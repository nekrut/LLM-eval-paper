#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

BWA_INDEXES=("${REF}.amb" "${REF}.ann" "${REF}.bwt" "${REF}.pac" "${REF}.sa")
ALL_BWA_EXISTS=true
for idx in "${BWA_INDEXES[@]}"; do
    if [[ ! -f "$idx" ]]; then
        ALL_BWA_EXISTS=false
        break
    fi
done

if [ "$ALL_BWA_EXISTS" = false ]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    FQ1="data/raw/${sample}_1.fq.gz"
    FQ2="data/raw/${sample}_2.fq.gz"
    BAM="$OUT_DIR/${sample}.bam"
    BAI="$BAM.bai"
    VCF_GZ="$OUT_DIR/${sample}.vcf.gz"
    TBI="$VCF_GZ.tbi"

    if [[ -f "$TBI" && "$TBI" -nt "$FQ1" && "$TBI" -nt "$FQ2" ]]; then
        continue
    fi

    RG_STR="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
    
    bwa mem -t "$THREADS" -R "$RG_STR" "$REF" "$FQ1" "$FQ2" | \
        samtools sort -@ "$THREADS" -o "$BAM"

    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    VCF_UNCOMPRESSED="$OUT_DIR/${sample}.vcf"
    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF_UNCOMPRESSED" "$BAM"
        
        # bgzip is part of htslib/samtools suite, using samtools view -Oz as a robust alternative if bgzip not explicitly in inventory but bcftools/samtools are. 
        # However, instruction says use bgzip. Since it's standard with htslib (which provides tabix), we use it.
        bgzip -c "$VCF_UNCOMPRESSED" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$VCF_UNCOMPRESSED"
    fi
done

TSV="$OUT_DIR/collapsed.tsv"
REBUILD_TSV=false

if [[ ! -f "$TSV" ]]; then
    REBUILD_TSV=true
else
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="$OUT_DIR/${sample}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$TSV" ]]; then
            REBUILD_TSV=true
            break
        fi
    done
fi

if [ "$REBUILD_TSV" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TSV"
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="$OUT_DIR/${sample}.vcf.gz"
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$TSV"
    done
fi

exit 0