#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# 2. Reference indexing (once, in data/ref/)
if [[ ! -f "${REF}.fai" ]] || [[ ! -f "${REF}.bwt" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${OUT_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Idempotency guard: if final artifacts exist, skip sample
    if [[ -f "$TBI" ]]; then
        continue
    fi

    FQ1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    FQ2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # 3 & 4. Alignment and sorting
    # Note: \t in the read group string is literal backslash-t as required by bwa mem
    RG="-R \"@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA\""

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" $RG "$REF" "$FQ1" "$FQ2" | \
            samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    # 5. BAM indexing
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # 6. Variant calling with lofreq
    VCF_UNCOMP="${OUT_DIR}/${SAMPLE}.vcf"
    if [[ ! -f "$VCF_GZ" ]]; then
        # If uncompressed vcf exists but gz doesn't, we might need to re-call or just compress?
        # Plan says: lofreq call-parallel -> results/{sample}.vcf. Then compress.
        # To be safe and idempotent, if VCF_GZ is missing, we ensure VCF_UNCOMP exists.
        if [[ ! -f "$VCF_UNCOMP" ]]; then
            lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF_UNCOMP" "$BAM"
        fi

        # 7. VCF compression and indexing
        bgzip -c "$VCF_UNCOMP" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm -f "$VCF_UNCOMP"
    fi
done

# 8. Collapse step -> results/collapsed.tsv
TSV="${OUT_DIR}/collapsed.tsv"
REBUILD_TSV=false

# Check if TSV exists and is newer than all VCFs
if [[ ! -f "$TSV" ]]; then
    REBUILD_TSV=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$TSV" ]]; then
            REBUILD_TSV=true
            break
        fi
    done
fi

if $REBUILD_TSV; then
    TMP_TSV=$(mktemp)
    # Header
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TMP_TSV"

    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        # bcftools query format: {sample} is literal text, %CHROM etc are fields.
        # We need to inject the sample name into the output.
        # The plan says: bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n'
        # This will literally print "{sample}" if not substituted.
        # However, standard bcftools query doesn't support variable substitution in the format string directly like that.
        # We must use shell expansion or awk.
        # Let's use awk to prepend the sample name to ensure correctness and tab separation.
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF_GZ" | \
            awk -v s="$SAMPLE" '{print s "\t" $0}' >> "$TMP_TSV"
    done

    mv "$TMP_TSV" "$TSV"
fi