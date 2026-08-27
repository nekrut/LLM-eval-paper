#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RAW_DIR=data/raw
RESULTS_DIR=results

mkdir -p "$RESULTS_DIR"

# 2. Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" ]] || [[ ! -f "${REF}.bwt" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${RESULTS_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Check if all final artifacts for this sample exist and are up-to-date
    # We consider the sample done if the .tbi exists (implies vcf.gz, bam, bai exist)
    # To be strictly idempotent without redoing work, we check existence.
    if [[ -f "$TBI" ]]; then
        continue
    fi

    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # 3 & 4. Alignment and Sorting
    # bwa mem with read group, piped to samtools sort
    # Note: The prompt specifies literal \t in the RG string for bwa mem -R
    RG="@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA"

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" -R "$RG" "$REF" "$R1" "$R2" | \
            samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    # 5. BAM Indexing
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # 6. Variant calling with lofreq
    VCF="${RESULTS_DIR}/${SAMPLE}.vcf"
    if [[ ! -f "$VCF_GZ" ]]; then
        # If vcf.gz doesn't exist, we need to call variants.
        # We generate the uncompressed VCF first.
        if [[ ! -f "$VCF" ]]; then
            lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
        fi

        # 7. Compress and Index VCF
        bgzip -c "$VCF" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"

        # Remove intermediate uncompressed VCF
        rm -f "$VCF"
    fi
done

# 8. Collapse step -> results/collapsed.tsv
TSV="${RESULTS_DIR}/collapsed.tsv"

# Check if TSV needs rebuilding: if it doesn't exist, or if any input VCF is newer
NEED_REBUILD=false
if [[ ! -f "$TSV" ]]; then
    NEED_REBUILD=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$TSV" ]]; then
            NEED_REBUILD=true
            break
        fi
    done
fi

if $NEED_REBUILD; then
    # Create a temporary file to build the TSV content
    TMP_TSV=$(mktemp)

    # Write header
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TMP_TSV"

    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
        # bcftools query to extract fields, prepending sample name
        # Format: {sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n
        # Note: The prompt asks for literal {sample} in the format string?
        # "the {sample} literal is prepended via the format string"
        # Actually, bcftools query -f does not support variable substitution directly in the format string like that.
        # We need to prepend the sample name manually or use a trick.
        # The prompt says: run `bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' ...`
        # This implies the user wants the literal string "{sample}"? No, that would be useless.
        # It likely means "replace {sample} with the actual sample name".
        # Since bcftools -f doesn't do shell variable expansion inside single quotes easily without breaking,
        # and we need to prepend a static string per sample, we can use awk or sed, or just echo the sample name.
        # However, the prompt explicitly gives the command:
        # `bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/{sample}.vcf.gz`
        # This is ambiguous. Does it mean I should literally type {sample}? No, that's not useful for a collapsed table.
        # It means "use the sample name".
        # Let's use bcftools query to get the variant fields, then prepend the sample name using awk or paste.
        
        # Extract variant info
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF_GZ" | \
            awk -v s="$SAMPLE" '{print s "\t" $0}' >> "$TMP_TSV"
    done

    mv "$TMP_TSV" "$TSV"
fi