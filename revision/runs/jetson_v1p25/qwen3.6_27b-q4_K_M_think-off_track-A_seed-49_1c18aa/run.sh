#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RES_DIR="results"

mkdir -p "$RES_DIR"

# 2. Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" ]] || [[ ! -f "${REF}.bwt" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${RES_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${RES_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Check if final variant artifacts exist and are up-to-date relative to inputs
    # We check the TBI as the last artifact of the per-sample pipeline.
    # If it exists, we assume the whole chain is done for this sample.
    if [[ -f "$TBI" ]]; then
        continue
    fi

    FQ1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    FQ2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # 3 & 4. Alignment and Sorting (idempotent: skip if BAM exists)
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
            "$REF" "$FQ1" "$FQ2" | \
        samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    # 5. BAM indexing (idempotent)
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    VCF="${RES_DIR}/${SAMPLE}.vcf"

    # 6. Variant calling (idempotent: skip if uncompressed VCF exists, or if gzipped version exists)
    # Note: lofreq call-parallel outputs to file specified by -o.
    if [[ ! -f "$VCF_GZ" ]]; then
        # If we have the uncompressed VCF but not the gzipped one, we can skip calling and go straight to compression.
        # However, to keep logic simple: if gzipped doesn't exist, we might need to call.
        # But if uncompressed exists, we don't need to call again.
        
        if [[ ! -f "$VCF" ]]; then
            lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
        fi

        # 7. VCF compression and indexing
        # bgzip is part of htslib/samtools suite usually, or available as bgzip. 
        # The tool inventory lists tabix (htslib) 1.21. bgzip is typically in the same package.
        # If bgzip command is missing, we can use samtools view -Oz but plan says "Compress with bgzip".
        # Let's assume bgzip is available as it's standard with htslib/tabix.
        
        if [[ ! -f "$VCF_GZ" ]]; then
            bgzip -c "$VCF" > "$VCF_GZ"
        fi

        if [[ ! -f "$TBI" ]]; then
            tabix -p vcf "$VCF_GZ"
        fi

        # Remove intermediate uncompressed VCF
        rm -f "$VCF"
    fi
done

# 8. Collapse step -> results/collapsed.tsv
COLLAPSED="${RES_DIR}/collapsed.tsv"

# Check if collapsed.tsv needs rebuilding.
# It needs rebuilding if it doesn't exist, or if any input VCF.gz is newer than it.
NEED_REBUILD=false
if [[ ! -f "$COLLAPSED" ]]; then
    NEED_REBUILD=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${RES_DIR}/${SAMPLE}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$COLLAPSED" ]]; then
            NEED_REBUILD=true
            break
        fi
    done
fi

if $NEED_REBUILD; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for SAMPLE in "${SAMPLES[@]}"; do
            VCF_GZ="${RES_DIR}/${SAMPLE}.vcf.gz"
            # bcftools query format: 
            # We want sample name, chrom, pos, ref, alt, AF from INFO.
            # The plan says: bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n'
            # Note: {sample} in the format string is a literal placeholder for the variable $SAMPLE? 
            # No, bcftools query -f does not expand shell variables inside the quotes automatically unless passed.
            # The plan says: "the {sample} literal is prepended via the format string so the sample name is attached per row"
            # This implies we should use the literal string of the sample name in the format string? 
            # Or does it mean we pass the sample name as a variable to bcftools?
            # Let's look at the exact command in plan:
            # bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/{sample}.vcf.gz
            # This is ambiguous. If I put literal "{sample}" it will print "{sample}".
            # It likely means: use the shell variable $SAMPLE in the format string.
            # So: -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n"
            
            bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ"
        done
    } > "$COLLAPSED"
fi